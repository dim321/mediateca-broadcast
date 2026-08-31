# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: screens
#
#  id                    :bigint           not null, primary key
#  name                  :string           not null
#  orientation           :string           default("landscape"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  owner_organization_id :bigint
#  station_id            :bigint           not null
#
# Indexes
#
#  index_screens_on_owner_organization_id  (owner_organization_id)
#  index_screens_on_station_id             (station_id)
#  index_screens_on_station_id_and_name    (station_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (owner_organization_id => organizations.id)
#  fk_rails_...  (station_id => stations.id)
#
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

    expect(screen.name).to eq("ТЦ Командор-Касса-screen-1")
  end

  it "keeps an explicitly provided name" do
    station = create(:station, name: "Касса", location: create(:location, name: "ТЦ Командор"))

    screen = described_class.create!(station: station, name: "Витрина 1")

    expect(screen.name).to eq("Витрина 1")
  end
end
