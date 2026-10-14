# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Screens::Synchronize do
  subject(:synchronize) { described_class.call(station:, screens:) }

  let(:location) { create(:location, name: "ТЦ") }
  let(:station) { create(:station, location:, name: "Касса") }
  let(:screens) { [] }

  def discovered(mac_address, ip_address)
    { mac_address:, ip_address: }
  end

  it "updates an existing screen by normalized MAC and preserves its settings" do
    screen = create(
      :screen,
      station:,
      name: "Витрина",
      orientation: :portrait,
      mac_address: "aa:bb:cc:dd:ee:ff",
      ip_address: "192.168.1.2"
    )
    screens = [ discovered("AA-BB-CC-DD-EE-FF", "192.168.1.20") ]

    described_class.call(station:, screens:)

    expect(screen.reload).to have_attributes(
      name: "Витрина",
      orientation: "portrait",
      ip_address: IPAddr.new("192.168.1.20"),
      network_registered: true
    )
  end

  it "unregisters missing screens without clearing their network identity" do
    present = create(:screen, station:, mac_address: "aa:bb:cc:dd:ee:01", network_registered: true)
    missing = create(
      :screen,
      station:,
      mac_address: "aa:bb:cc:dd:ee:02",
      ip_address: "192.168.1.2",
      network_registered: true
    )
    legacy = create(:screen, station:, mac_address: nil, network_registered: true)
    screens = [ discovered("aa:bb:cc:dd:ee:01", "192.168.1.1") ]

    described_class.call(station:, screens:)

    expect(present.reload).to be_network_registered
    expect(missing.reload).to have_attributes(
      mac_address: "aa:bb:cc:dd:ee:02",
      ip_address: IPAddr.new("192.168.1.2"),
      network_registered: false
    )
    expect(legacy.reload.mac_address).to be_nil
    expect(legacy).not_to be_network_registered
  end

  it "unregisters every station screen for an empty discovery" do
    registered = create(:screen, station:, network_registered: true)
    another = create(:screen, station:, network_registered: true)

    synchronize

    expect([ registered.reload, another.reload ]).to all(satisfy { !_1.network_registered? })
  end

  it "creates unknown screens in numeric IPv4 order with sequential default names" do
    screens = [
      discovered("aa:bb:cc:dd:ee:20", "192.168.1.20"),
      discovered("aa:bb:cc:dd:ee:03", "192.168.1.3")
    ]

    described_class.call(station:, screens:)

    created = station.screens.order(:id)
    expect(created.pluck(:ip_address).map(&:to_s)).to eq(%w[192.168.1.3 192.168.1.20])
    expect(created.pluck(:name)).to eq(%w[ТЦ-Касса-screen-1 ТЦ-Касса-screen-2])
    expect(created).to all(be_network_registered)
    expect(created).to all(have_attributes(orientation: "landscape"))
  end

  it "does not match or modify the same MAC at another station" do
    foreign_station = create(:station, location:)
    foreign = create(
      :screen,
      station: foreign_station,
      name: "Foreign",
      mac_address: "aa:bb:cc:dd:ee:ff",
      ip_address: "192.168.1.1",
      network_registered: false
    )
    screens = [ discovered("aa:bb:cc:dd:ee:ff", "192.168.1.2") ]

    described_class.call(station:, screens:)

    expect(station.screens.sole).to have_attributes(
      mac_address: "aa:bb:cc:dd:ee:ff",
      ip_address: IPAddr.new("192.168.1.2"),
      network_registered: true
    )
    expect(foreign.reload).to have_attributes(
      name: "Foreign",
      ip_address: IPAddr.new("192.168.1.1"),
      network_registered: false
    )
  end

  it "is idempotent and preserves the generated name" do
    screens = [ discovered("aa:bb:cc:dd:ee:ff", "192.168.1.2") ]

    2.times { described_class.call(station:, screens:) }

    expect(station.screens.count).to eq(1)
    expect(station.screens.sole.name).to eq("ТЦ-Касса-screen-1")
  end

  it "rejects an invalid payload before changing the database" do
    screen = create(
      :screen,
      station:,
      mac_address: "aa:bb:cc:dd:ee:ff",
      ip_address: "192.168.1.1",
      network_registered: true
    )

    expect {
      described_class.call(station:, screens: [ discovered("invalid", "192.168.1.2") ])
    }.to raise_error(Agent::Screens::NormalizeDiscovery::Invalid)

    expect(screen.reload).to have_attributes(
      ip_address: IPAddr.new("192.168.1.1"),
      network_registered: true
    )
  end

  it "rolls back earlier updates when a later create fails" do
    existing = create(
      :screen,
      station:,
      mac_address: "aa:bb:cc:dd:ee:01",
      ip_address: "192.168.1.1",
      network_registered: false
    )
    screens = [
      discovered("aa:bb:cc:dd:ee:01", "192.168.1.10"),
      discovered("aa:bb:cc:dd:ee:02", "192.168.1.20"),
      discovered("aa:bb:cc:dd:ee:03", "192.168.1.30")
    ]
    callback = lambda do |screen|
      next unless screen.mac_address.to_s == "aa:bb:cc:dd:ee:03"

      screen.errors.add(:base, "forced failure")
      raise ActiveRecord::RecordInvalid, screen
    end

    Screen.set_callback(:create, :before, callback)
    expect {
      described_class.call(station:, screens:)
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(existing.reload).to have_attributes(
      ip_address: IPAddr.new("192.168.1.1"),
      network_registered: false
    )
    expect(station.screens.count).to eq(1)
  ensure
    Screen.skip_callback(:create, :before, callback) if callback
  end
end
