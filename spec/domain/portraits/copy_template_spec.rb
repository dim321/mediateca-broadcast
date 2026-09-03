# frozen_string_literal: true

require "rails_helper"

RSpec.describe Portraits::CopyTemplate do
  include ActiveJob::TestHelper

  let(:station) { create(:station) }

  it "returns nil and does not create a portrait when there is no default template" do
    create(:broadcast_portrait, :template)

    expect(described_class.call(station: station)).to be_nil
    expect(station.reload.broadcast_portrait).to be_nil
  end

  it "copies the default template and its blocks onto the station" do
    template = create(:broadcast_portrait, :default, name: "Grid", block_frequency_per_hour: 6,
      max_commercial_in_row: 2, neutral_min_seconds: 10)
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: template, position: 1)
    filler = create(:broadcast_portrait_block, :filler, broadcast_portrait: template, position: 2)

    portrait = described_class.call(station: station)

    expect(portrait).to be_persisted
    expect(portrait.station).to eq(station)
    expect(portrait.is_default).to be(false)
    expect(portrait.name).to eq("Grid")
    expect(portrait.block_frequency_per_hour).to eq(6)
    expect(portrait.max_commercial_in_row).to eq(2)
    expect(portrait.blocks.order(:position).map(&:kind)).to eq(%w[commercial filler])
    expect(portrait.blocks.find_by!(position: 2).rotation).to eq(filler.rotation)
  end

  it "does not cascade later template edits onto the copy" do
    template = create(:broadcast_portrait, :default, name: "Grid")
    described_class.call(station: station)

    template.update!(name: "Night grid")

    expect(station.reload.broadcast_portrait.name).to eq("Grid")
  end

  it "returns the existing station portrait without duplicating" do
    create(:broadcast_portrait, :default)
    existing = create(:broadcast_portrait, :for_station, station: station)

    expect(described_class.call(station: station)).to eq(existing)
    expect(BroadcastPortrait.where(station: station).count).to eq(1)
  end

  it "copies a specific template even when another is the default" do
    create(:broadcast_portrait, :default, name: "Default grid")
    chosen = create(:broadcast_portrait, :template, name: "Lobby grid", block_frequency_per_hour: 8)
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: chosen, position: 1)

    portrait = described_class.call(station: station, template: chosen)

    expect(portrait.name).to eq("Lobby grid")
    expect(portrait.block_frequency_per_hour).to eq(8)
    expect(portrait.blocks.map(&:kind)).to eq(%w[commercial])
  end

  it "replaces an existing station portrait and enqueues regen" do
    create(:broadcast_portrait, :default, name: "Old grid")
    described_class.call(station: station)
    replacement = create(:broadcast_portrait, :template, name: "Night grid")
    create(:broadcast_portrait_block, :filler, broadcast_portrait: replacement, position: 1)

    expect {
      described_class.call(station: station, template: replacement, replace: true)
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

    portrait = station.reload.broadcast_portrait
    expect(portrait.name).to eq("Night grid")
    expect(portrait.blocks.map(&:kind)).to eq(%w[filler])
    expect(BroadcastPortrait.where(station: station).count).to eq(1)
  end
end
