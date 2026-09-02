# frozen_string_literal: true

require "rails_helper"

RSpec.describe Portraits::UpsertBlocks do
  include ActiveJob::TestHelper

  let(:portrait) { create(:broadcast_portrait) }
  let(:rotation) { create(:rotation) }

  it "enqueues regen for a station portrait after success" do
    station = create(:station)
    station_portrait = create(:broadcast_portrait, :for_station, station: station)

    expect {
      described_class.call(
        portrait: station_portrait,
        blocks: [ { position: 1, kind: "commercial" } ]
      )
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)
  end

  it "does not enqueue regen for a template portrait" do
    expect {
      described_class.call(
        portrait: portrait,
        blocks: [ { position: 1, kind: "commercial" } ]
      )
    }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
  end

  it "replaces blocks in the given order" do
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)

    described_class.call(
      portrait: portrait,
      blocks: [
        { position: 1, kind: "filler", rotation_id: rotation.id, pick_strategy: "sequential" },
        { position: 2, kind: "commercial" }
      ]
    )

    expect(portrait.blocks.order(:position).map(&:kind)).to eq(%w[filler commercial])
    expect(portrait.blocks.find_by!(position: 1).rotation).to eq(rotation)
  end

  it "rejects kind-specific field mismatches and leaves existing blocks" do
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)

    expect {
      described_class.call(
        portrait: portrait,
        blocks: [ { position: 1, kind: "filler" } ]
      )
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(portrait.blocks.reload.map(&:kind)).to eq(%w[commercial])
  end
end
