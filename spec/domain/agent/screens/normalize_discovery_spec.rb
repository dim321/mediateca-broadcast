# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Screens::NormalizeDiscovery do
  subject(:normalize) { described_class.call(screens:) }

  let(:screens) { [ { mac_address: "AA-BB-CC-DD-EE-FF", ip_address: "192.0.2.10" } ] }

  it "canonicalizes addresses into an immutable pair" do
    pair = normalize.fetch(0)

    expect(pair).to be_a(described_class::Pair)
    expect(pair.mac_address).to eq("aa:bb:cc:dd:ee:ff")
    expect(pair.ip_address).to eq(IPAddr.new("192.0.2.10"))
    expect(pair).to be_frozen
  end

  {
    "aa:bb:cc:dd:ee:ff" => "aa:bb:cc:dd:ee:ff",
    "AA-BB-CC-DD-EE-FF" => "aa:bb:cc:dd:ee:ff",
    "AABBCCDDEEFF" => "aa:bb:cc:dd:ee:ff",
    "AABB.CCDD.EEFF" => "aa:bb:cc:dd:ee:ff"
  }.each do |input, canonical|
    it "normalizes supported MAC form #{input}" do
      screens = [ { "mac_address" => input, "ip_address" => "198.51.100.7" } ]

      result = described_class.call(screens:)

      expect(result.first.mac_address).to eq(canonical)
    end
  end

  it "deduplicates exact normalized pairs" do
    screens = [
      { mac_address: "AA-BB-CC-DD-EE-FF", ip_address: "192.0.2.10" },
      { mac_address: "aabbccddeeff", ip_address: "192.0.2.10" }
    ]

    expect(described_class.call(screens:).size).to eq(1)
  end

  it "accepts an empty collection" do
    expect(described_class.call(screens: [])).to eq([])
  end

  [ nil, {}, "not-an-array" ].each do |input|
    it "rejects non-array input #{input.inspect}" do
      expect {
        described_class.call(screens: input)
      }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects rows with missing keys" do
    rows = [
      { ip_address: "192.0.2.10" },
      { mac_address: "aa:bb:cc:dd:ee:ff" }
    ]

    rows.each do |row|
      expect {
        described_class.call(screens: [ row ])
      }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects rows that cannot become hashes" do
    [ nil, "not-a-row" ].each do |row|
      expect {
        described_class.call(screens: [ row ])
      }.to raise_error(described_class::Invalid)
    end
  end

  [ "", "aa:bb:cc:dd:ee", "gg:bb:cc:dd:ee:ff", "aa bb cc dd ee ff" ].each do |mac_address|
    it "rejects malformed MAC #{mac_address.inspect}" do
      screens = [ { mac_address:, ip_address: "192.0.2.10" } ]

      expect {
        described_class.call(screens:)
      }.to raise_error(described_class::Invalid)
    end
  end

  [ "", "999.0.0.1", "not-an-ip" ].each do |ip_address|
    it "rejects malformed IPv4 #{ip_address.inspect}" do
      screens = [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: } ]

      expect {
        described_class.call(screens:)
      }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects IPv6" do
    screens = [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "2001:db8::1" } ]

    expect {
      described_class.call(screens:)
    }.to raise_error(described_class::Invalid)
  end

  it "rejects CIDR notation" do
    screens = [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.0.2.10/24" } ]

    expect {
      described_class.call(screens:)
    }.to raise_error(described_class::Invalid)
  end

  it "rejects one MAC associated with different IPs" do
    screens = [
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.0.2.10" },
      { mac_address: "aa-bb-cc-dd-ee-ff", ip_address: "192.0.2.11" }
    ]

    expect {
      described_class.call(screens:)
    }.to raise_error(described_class::Invalid)
  end

  it "rejects one IP associated with different MACs" do
    screens = [
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.0.2.10" },
      { mac_address: "11:22:33:44:55:66", ip_address: "192.0.2.10" }
    ]

    expect {
      described_class.call(screens:)
    }.to raise_error(described_class::Invalid)
  end

  it "exposes one Invalid error type for payload errors" do
    invalid_payloads = [
      [ Object.new ],
      [ { mac_address: Object.new, ip_address: "192.0.2.10" } ],
      [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: Object.new } ]
    ]

    invalid_payloads.each do |payload|
      expect {
        described_class.call(screens: payload)
      }.to raise_error(described_class::Invalid)
    end
  end
end
