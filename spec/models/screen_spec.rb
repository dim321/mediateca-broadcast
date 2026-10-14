# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: screens
#
#  id                                    :bigint           not null, primary key
#  inherit_operating_hours_from_location :boolean          default(TRUE), not null
#  ip_address                            :inet
#  mac_address                           :macaddr
#  name                                  :string           not null
#  network_registered                    :boolean          default(FALSE), not null
#  operating_hours                       :jsonb            not null
#  orientation                           :string           default("landscape"), not null
#  created_at                            :datetime         not null
#  updated_at                            :datetime         not null
#  owner_organization_id                 :bigint
#  station_id                            :bigint           not null
#
# Indexes
#
#  index_screens_on_owner_organization_id       (owner_organization_id)
#  index_screens_on_station_id                  (station_id)
#  index_screens_on_station_id_and_mac_address  (station_id,mac_address) UNIQUE WHERE (mac_address IS NOT NULL)
#  index_screens_on_station_id_and_name         (station_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (owner_organization_id => organizations.id)
#  fk_rails_...  (station_id => stations.id)
#
RSpec.describe Screen, type: :model do
  describe "network identity" do
    it "uses PostgreSQL network types" do
      expect(described_class.columns_hash.fetch("mac_address").sql_type).to eq("macaddr")
      expect(described_class.columns_hash.fetch("ip_address").sql_type).to eq("inet")
    end

    it "canonicalizes MAC addresses" do
      screen = create(:screen, mac_address: "08-00-2B-01-02-03")

      expect(screen.reload.mac_address.to_s).to eq("08:00:2b:01:02:03")
    end

    it "does not register a screen by default" do
      expect(create(:screen).network_registered).to be(false)
    end

    it "accepts an IPv4 host address" do
      expect(build(:screen, ip_address: "192.0.2.10")).to be_valid
    end

    it "rejects an IPv6 address" do
      screen = build(:screen, ip_address: "2001:db8::1")

      expect(screen).not_to be_valid
      expect(screen.errors[:ip_address]).to include(I18n.t("errors.messages.invalid"))
    end

    it "rejects an IPv4 CIDR" do
      screen = build(:screen, ip_address: "192.0.2.10/24")

      expect(screen).not_to be_valid
      expect(screen.errors[:ip_address]).to include(I18n.t("errors.messages.invalid"))
    end

    it "requires MAC addresses to be unique within a station" do
      station = create(:station)
      create(:screen, station: station, mac_address: "08:00:2b:01:02:03")

      duplicate = build(:screen, station: station, mac_address: "08:00:2b:01:02:03")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:mac_address]).to be_present
    end

    it "allows the same MAC address at different stations" do
      create(:screen, mac_address: "08:00:2b:01:02:03")

      expect(build(:screen, mac_address: "08:00:2b:01:02:03")).to be_valid
    end

    it "enforces MAC uniqueness within a station at the database level" do
      station = create(:station)
      create(:screen, station: station, mac_address: "08:00:2b:01:02:03")

      duplicate = create(:screen, station: station)

      expect {
        duplicate.update_columns(mac_address: "08:00:2b:01:02:03")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects IPv6 at the database level" do
      screen = create(:screen)

      expect {
        screen.update_columns(ip_address: "2001:db8::1")
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

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

  describe "template_id" do
    it "rejects a portrait that already belongs to a screen" do
      screen_portrait = create(:broadcast_portrait, :for_screen)
      screen = build(:screen, template_id: screen_portrait.id)

      expect(screen).not_to be_valid
      expect(screen.errors[:template_id]).to be_present
    end

    it "accepts a template portrait" do
      template = create(:broadcast_portrait, :template)
      screen = build(:screen, template_id: template.id)

      expect(screen).to be_valid
    end
  end

  describe "#effective_operating_hours" do
    it "inherits location hours by default" do
      location = create(:location, operating_hours: { "mon" => [ { "start" => "09:00", "end" => "18:00" } ] })
      screen = create(:screen, station: create(:station, location: location))

      expect(screen.inherit_operating_hours_from_location).to be(true)
      expect(screen.effective_operating_hours).to eq(location.operating_hours)
    end

    it "uses screen hours when inheritance is off" do
      location = create(:location, operating_hours: { "mon" => [ { "start" => "09:00", "end" => "18:00" } ] })
      screen = create(
        :screen,
        station: create(:station, location: location),
        inherit_operating_hours_from_location: false,
        operating_hours: { "mon" => [ { "start" => "10:00", "end" => "20:00" } ] }
      )

      expect(screen.effective_operating_hours["mon"].first["start"]).to eq("10:00")
    end
  end
end
