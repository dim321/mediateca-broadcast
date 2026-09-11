# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rotations::ReorderItems do
  include ActiveJob::TestHelper

  it "enqueues regen from the rotation after a successful reorder" do
    rotation = create(:rotation)
    first = create(:rotation_item, rotation: rotation)
    second = create(:rotation_item, rotation: rotation)
    station = create(:station)
    portrait = create(:broadcast_portrait, :for_screen, screen: create(:screen, station: station))
    create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, rotation: rotation)

    expect {
      described_class.call(rotation: rotation, ordered_ids: [ second.id, first.id ])
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)
  end
end
